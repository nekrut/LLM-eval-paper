#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Step 2: reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai || ! -f data/ref/chrM.fa.bwt ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Step 3-5: per-sample alignment, sorting, indexing
for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_uncomp=results/${sample}.vcf
    vcf_gz=results/${sample}.vcf.gz

    if [[ -f "$bai" && $bai -nt data/raw/${sample}_1.fq.gz && $bai -nt data/raw/${sample}_2.fq.gz ]]; then
        continue
    fi

    if [[ ! -f "$bam" || "$bam" -nt "${vcf_gz}" ]]; then
        bwa mem -t 4 \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz |
        samtools sort -@ 4 -o "$bam"
    fi

    if [[ ! -f "$bai" || "$bai" -nt "$bam" ]]; then
        samtools index -@ 4 "$bam"
    fi

    # Step 6-7: variant calling and compression/indexing
    if [[ ! -f "$vcf_gz.tbi" || "$vcf_gz.tbi" -nt "$bam" ]]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o "$vcf_uncomp" "$bam"
        bgzip "$vcf_uncomp"
        tabix -p vcf "$vcf_gz"
        rm "$vcf_uncomp"
    fi
done

# Step 8: collapse step
collapsed=results/collapsed.tsv
if [[ ! -f "$collapsed" || "$collapsed" -nt results/*.vcf.gz ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz
        done
    } > "$collapsed"
fi

exit 0