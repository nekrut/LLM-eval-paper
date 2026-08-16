#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Function to process a sample given R1 and R2 fastq files
process_sample() {
    local base=$1
    local r1=$2
    local r2=$3

    # Skip if final outputs already exist
    if [[ -f "results/${base}.vcf.gz.tbi" ]]; then
        return 0
    fi

    # Align with BWA-MEM
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "results/${base}.bam"

    # Sort and index the BAM file
    samtools sort -@ 4 -o "results/${base}.sorted.bam" "results/${base}.bam"
    samtools index "results/${base}.sorted.bam"

    # Run lofreq depth filtering (using default parameters)
    lofreq depth --min-base-quality 20 --min-read-depth 10 \
        -i <(samtools view -h "results/${base}.sorted.bam" | \
               awk '$1 ~ /^@/ || ($3 != "*" && $5 >= 0)') \
        > "results/${base}.depth.txt"

    # Call variants with lofreq
    lofreq call --min-base-quality 20 --min-read-depth 10 \
        -d "results/${base}.depth.txt" \
        -o "results/${base}.vcf.gz" \
        data/ref/chrM.fa "results/${base}.sorted.bam"

    # Index the VCF
    bcftools index "results/${base}.vcf.gz"
    tabix -p vcf "results/${base}.vcf.gz.tbi" "results/${base}.vcf.gz"

    # Clean up intermediate files to keep only required outputs
    rm -f "results/${base}.bam" "results/${base}.sorted.bam" \
          "results/${base}.depth.txt"
}

# Process each sample in parallel (max 4 jobs)
samples=(
    M117-bl
    M117-ch
    M117C1-bl
    M117C1-ch
)

export -f process_sample
export results data/ref/chrM.fa

parallel -j 4 process_sample ::: "${samples[@]}" \
    ::: $(printf '%s_1.fq.gz ' */*_1.fq.gz | sed 's/ $//') \
    ::: $(printf '%s_2.fq.gz' */*_2.fq.gz)

# Collapse VCFs into a single TSV
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%CHROM %POS %REF %ALT [ADF]\n' \
            -i "results/${sample}.vcf.gz" |
        awk -v s="$sample" '
            {
                split($0, a, / +/);
                ref = a[3];
                alt = a[4];
                # Extract ADF (Allelic Depths Forward) from INFO field
                match($0, /ADF=([0-9]+)/, arr);
                af_num = arr[1] + 0;
                total_depth = 0;
                for(i=5;i<=NF;i++) {
                    if ($i ~ /^DP4=/) {
                        split(substr($i,6), d, ",");
                        total_depth += d[1]+d[2]+d[3]+d[4];
                        break;
                    }
                }
                af = (total_depth > 0) ? af_num/total_depth : 0;
                printf "%s\t%s\t%d\t%s\t%s\t%.6f\n", s, a[1], a[2], ref, alt, af
            }'
    done
} | sort -k2,2 -k3,3n > results/collapsed.tsv

exit 0