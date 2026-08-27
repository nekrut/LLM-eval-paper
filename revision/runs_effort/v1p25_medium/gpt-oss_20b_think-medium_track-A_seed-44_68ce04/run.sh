#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

needs_run() {
    local out=$1; shift
    if [[ ! -f $out ]]; then return 0; fi
    for inp in "$@"; do
        if [[ ! -f $inp ]]; then continue; fi
        if [[ $(stat -c %Y "$inp") -gt $(stat -c %Y "$out") ]]; then
            return 0
        fi
    done
    return 1
}

REF=data/ref/chrM.fa
FAI=${REF}.fai
AMB=${REF}.amb

if needs_run "$FAI" "$REF"; then
    samtools faidx "$REF"
fi
if needs_run "$AMB" "$REF"; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM=results/${sample}.bam
    BAI=${BAM}.bai
    VCF=results/${sample}.vcf
    VCFZ=results/${sample}.vcf.gz
    TBIVCFZ=${VCFZ}.tbi

    if needs_run "$BAM" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz "$FAI"; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if needs_run "$BAI" "$BAM"; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if needs_run "$VCFZ" "$BAM"; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bcftools view -O z -o "$VCFZ" "$VCF"
        tabix -p vcf "$VCFZ"
        rm -f "$VCF"
    fi
done

COLLAPSED=results/collapsed.tsv
INPUTS=()
for s in "${SAMPLES[@]}"; do
    INPUTS+=("results/${s}.vcf.gz")
done

if needs_run "$COLLAPSED" "${INPUTS[@]}"; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' "results/${s}.vcf.gz" |
                awk -v samp="$s" '{print samp"\t"$0}'
        done
    } > "$COLLAPSED"
fi

exit 0